#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Reference indexing
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

bwa_index_files=(data/ref/chrM.fa.amb data/ref/chrM.fa.ann data/ref/chrM.fa.bwt data/ref/chrM.fa.pac data/ref/chrM.fa.sa)
if [ ! -f "${bwa_index_files[0]}" ]; then
    bwa index data/ref/chrM.fa
fi

for sample in "${samples[@]}"; do
    bam=results/${sample}.bam
    vcf_gz=results/${sample}.vcf.gz
    vcf_tbi=${vcf_gz}.tbi
    vcf=results/${sample}.vcf

    # Alignment and sorting
    if [ ! -f "$bam" ]; then
        bwa mem -t $THREADS \
            -R "@RG\\tID:${sample}\\tSM:${sample}\\tLB:${sample}\\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ $THREADS -o "$bam"
    fi

    # BAM indexing
    if [ ! -f "${bam}.bai" ]; then
        samtools index -@ $THREADS "$bam"
    fi

    # Variant calling and compression
    if [ ! -f "$vcf_gz" ] || [ ! -f "$vcf_tbi" ]; then
        lofreq call-parallel --pp-threads $THREADS \
            -f data/ref/chrM.fa \
            "$bam" > "$vcf"

        bgzip -c "$vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm "$vcf"
    fi
done

# Generate collapsed.tsv
collapsed=results/collapsed.tsv
needs_collapsed=false
if [ ! -f "$collapsed" ]; then
    needs_collapsed=true
else
    for sample in "${samples[@]}"; do
        if [ results/${sample}.vcf.gz -nt "$collapsed" ]; then
            needs_collapsed=true
            break
        fi
    done
fi

if $needs_collapsed; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for sample in "${samples[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
                results/${sample}.vcf.gz
        done
    } > "$collapsed"
fi

exit 0