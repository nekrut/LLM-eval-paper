#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

# Create results directory if missing
mkdir -p results

# Reference indexing
REF=data/ref/chrM.fa
if [[ ! -f ${REF}.fai ]]; then
    samtools faidx "$REF"
fi
if [[ ! -f ${REF}.amb || ! -f ${REF}.ann || ! -f ${REF}.bwt || ! -f ${REF}.pac || ! -f ${REF}.sa ]]; then
    bwa index "$REF"
fi

# Helper to check if output is up-to-date
is_up_to_date() {
    local out=$1; shift
    [[ -f "$out" ]] || return 1
    for inp in "$@"; do
        [[ -e $inp ]] || return 1
        [[ $out -nt $inp ]] || return 1
    done
    return 0
}

# Process each sample
for sample in "${SAMPLES[@]}"; do
    fq1=data/raw/${sample}_1.fq.gz
    fq2=data/raw/${sample}_2.fq.gz
    bam=results/${sample}.bam
    bai=results/${sample}.bam.bai
    vcf_uncompressed=results/${sample}.vcf
    vcf_gz=results/${sample}.vcf.gz
    tbi=results/${sample}.vcf.gz.tbi

    # Alignment and sorting
    if ! is_up_to_date "$bam" "$fq1" "$fq2"; then
        bwa mem -t $THREADS -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            "$REF" "$fq1" "$fq2" | samtools sort -@ $THREADS -o "$bam"
    fi
    if [[ ! -f "$bai" || "$bam" -nt "$bai" ]]; then
        samtools index -@ $THREADS "$bam"
    fi

    # Variant calling
    if ! is_up_to_date "$vcf_gz" "$bam"; then
        lofreq call-parallel --pp-threads $THREADS -f "$REF" -o "$vcf_uncompressed" "$bam"
        bgzip -c "$vcf_uncompressed" > "$vcf_gz"
        rm -f "$vcf_uncompressed"
    fi
    if [[ ! -f "$tbi" || "$vcf_gz" -nt "$tbi" ]]; then
        tabix -p vcf "$vcf_gz"
    fi
done

# Collapse step
collapsed=results/collapsed.tsv
needs_collapse=true
if [[ -s $collapsed ]]; then
    needs_collapse=false
    for sample in "${SAMPLES[@]}"; do
        vcf_gz=results/${sample}.vcf.gz
        if [[ "$vcf_gz" -nt "$collapsed" ]]; then
            needs_collapse=true
            break
        fi
    done
fi

if $needs_collapse; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed"
    for sample in "${SAMPLES[@]}"; do
        vcf_gz=results/${sample}.vcf.gz
        bcftools query -f '%CHROM\\t%POS\\t%REF\\t%ALT\\t%INFO/AF\\n' "$vcf_gz" | \
            awk -v s="$sample" '{print s"\t"$0}' >> "$collapsed"
    done
fi

exit 0