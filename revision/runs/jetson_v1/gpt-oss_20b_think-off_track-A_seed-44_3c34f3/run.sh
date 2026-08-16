#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

REF=data/ref/chrM.fa
if [ ! -f "${REF}.fai" ]; then
    samtools faidx "$REF"
fi
if [ ! -f "${REF}.bwt" ]; then
    bwa index "$REF"
fi

for sample in "${SAMPLES[@]}"; do
    fq1=data/raw/${sample}_1.fq.gz
    fq2=data/raw/${sample}_2.fq.gz
    bam=results/${sample}.bam
    bai=results/${sample}.bam.bai
    vcf_uncompressed=results/${sample}.vcf
    vcf_gz=results/${sample}.vcf.gz
    tbi=results/${sample}.vcf.gz.tbi

    if [ ! -f "$bam" ] || [ "$fq1" -nt "$bam" ] || [ "$fq2" -nt "$bam" ]; then
        bwa mem -t "$THREADS" -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            "$fq1" "$fq2" | samtools sort -@ "$THREADS" -o "$bam"
    fi

    if [ ! -f "$bai" ] || [ "$bam" -nt "$bai" ]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    if [ ! -f "$vcf_uncompressed" ] || [ "$bam" -nt "$vcf_uncompressed" ]; then
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" "$bam" > "$vcf_uncompressed"
    fi

    if [ ! -f "$vcf_gz" ] || [ "$vcf_uncompressed" -nt "$vcf_gz" ]; then
        bcftools view -O z -o "$vcf_gz" "$vcf_uncompressed"
        rm -f "$vcf_uncompressed"
    fi

    if [ ! -f "$tbi" ] || [ "$vcf_gz" -nt "$tbi" ]; then
        tabix -p vcf "$vcf_gz"
    fi
done

collapsed=results/collapsed.tsv
needs_rebuild=false
if [ ! -f "$collapsed" ]; then
    needs_rebuild=true
else
    for sample in "${SAMPLES[@]}"; do
        if [ "results/${sample}.vcf.gz" -nt "$collapsed" ]; then
            needs_rebuild=true
            break
        fi
    done
fi

if $needs_rebuild; then
    tmp=$(mktemp)
    cat <<'EOF' > "$tmp"
sample	chrom	pos	ref	alt	af
EOF
    for sample in "${SAMPLES[@]}"; do
        printf '%s\t' "$sample" >> "$tmp"
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" >> "$tmp"
    done
    mv "$tmp" "$collapsed"
fi

exit 0